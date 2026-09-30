# Which of Set's own methods its methods call on a subclass: every
# method Set defines is wrapped to log a call made from inside another,
# and each is then called once on a fresh receiver. CRuby calls one by
# dispatch only where it means to, and zr's core, written in Ruby, has
# to call no more and no fewer. Written by `zr-dev spec dispatch`.

class Probe < Set
  CALLING = []
  LOG = []
  [:&, :+, :-, :<, :<<, :<=, :<=>, :==, :===, :>, :>=, :^, :add, :add?, :all?, :any?, :chain, :chunk, :chunk_while, :classify, :clear, :collect, :collect!, :collect_concat, :compact, :compare_by_identity, :compare_by_identity?, :count, :cycle, :delete, :delete?, :delete_if, :detect, :difference, :disjoint?, :divide, :drop, :drop_while, :each, :each_cons, :each_entry, :each_slice, :each_with_index, :each_with_object, :empty?, :entries, :eql?, :filter, :filter!, :filter_map, :find, :find_all, :find_index, :first, :flat_map, :flatten, :flatten!, :grep, :grep_v, :group_by, :hash, :include?, :initialize_copy, :inject, :inspect, :intersect?, :intersection, :join, :keep_if, :lazy, :length, :map, :map!, :max, :max_by, :member?, :merge, :min, :min_by, :minmax, :minmax_by, :none?, :one?, :partition, :proper_subset?, :proper_superset?, :reduce, :reject, :reject!, :replace, :reset, :reverse_each, :select, :select!, :size, :slice_after, :slice_before, :slice_when, :sort, :sort_by, :subset?, :subtract, :sum, :superset?, :take, :take_while, :tally, :to_a, :to_h, :to_s, :to_set, :union, :uniq, :zip, :|].each do |m|
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
  r = Probe.new([1, 2, 3])
  Probe::LOG.clear
  begin
    yield r
  rescue StandardError => e
    Probe::LOG << "raised #{e.class}"
  end
  puts "#{name}: #{Probe::LOG.join(" ")}" unless Probe::LOG.empty?
end

call("&") { |r| r.__send__(:&, [1, 2]) { |*x| x.first } }
call("+") { |r| r.__send__(:+, [1, 2]) { |*x| x.first } }
call("-") { |r| r.__send__(:-, [1, 2]) { |*x| x.first } }
call("<<") { |r| r.__send__(:<<, 1) { |*x| x.first } }
call("<=>") { |r| r.__send__(:<=>, 1) { |*x| x.first } }
call("==") { |r| r.__send__(:==, 1) { |*x| x.first } }
call("===") { |r| r.__send__(:===, 1) { |*x| x.first } }
call("^") { |r| r.__send__(:^, [1, 2]) { |*x| x.first } }
call("add") { |r| r.add(1) { |*x| x.first } }
call("add?") { |r| r.add?(1) { |*x| x.first } }
call("all?") { |r| r.all?() { |*x| x.first } }
call("any?") { |r| r.any?() { |*x| x.first } }
call("chain") { |r| r.chain() { |*x| x.first } }
call("chunk") { |r| r.chunk() { |*x| x.first } }
call("chunk_while") { |r| r.chunk_while() { |*x| x.first } }
call("classify") { |r| r.classify() { |*x| x.first } }
call("clear") { |r| r.clear() { |*x| x.first } }
call("collect") { |r| r.collect() { |*x| x.first } }
call("collect!") { |r| r.collect!() { |*x| x.first } }
call("collect_concat") { |r| r.collect_concat() { |*x| x.first } }
call("compact") { |r| r.compact() { |*x| x.first } }
call("compare_by_identity") { |r| r.compare_by_identity() { |*x| x.first } }
call("compare_by_identity?") { |r| r.compare_by_identity?() { |*x| x.first } }
call("count") { |r| r.count() { |*x| x.first } }
call("delete") { |r| r.delete(1) { |*x| x.first } }
call("delete?") { |r| r.delete?(1) { |*x| x.first } }
call("delete_if") { |r| r.delete_if() { |*x| x.first } }
call("detect") { |r| r.detect() { |*x| x.first } }
call("difference") { |r| r.difference([1, 2]) { |*x| x.first } }
call("disjoint?") { |r| r.disjoint?([1, 2]) { |*x| x.first } }
call("divide") { |r| r.divide() { |*x| x.first } }
call("drop") { |r| r.drop(1) { |*x| x.first } }
call("drop_while") { |r| r.drop_while() { |*x| x.first } }
call("each") { |r| r.each() { |*x| x.first } }
call("each_cons") { |r| r.each_cons(1) { |*x| x.first } }
call("each_entry") { |r| r.each_entry() { |*x| x.first } }
call("each_slice") { |r| r.each_slice(1) { |*x| x.first } }
call("each_with_index") { |r| r.each_with_index() { |*x| x.first } }
call("each_with_object") { |r| r.each_with_object(1) { |*x| x.first } }
call("empty?") { |r| r.empty?() { |*x| x.first } }
call("entries") { |r| r.entries() { |*x| x.first } }
call("eql?") { |r| r.eql?(1) { |*x| x.first } }
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
call("inject") { |r| r.inject() { |*x| x.first } }
call("inspect") { |r| r.inspect() { |*x| x.first } }
call("intersect?") { |r| r.intersect?([1, 2]) { |*x| x.first } }
call("intersection") { |r| r.intersection([1, 2]) { |*x| x.first } }
call("join") { |r| r.join() { |*x| x.first } }
call("keep_if") { |r| r.keep_if() { |*x| x.first } }
call("lazy") { |r| r.lazy() { |*x| x.first } }
call("length") { |r| r.length() { |*x| x.first } }
call("map") { |r| r.map() { |*x| x.first } }
call("map!") { |r| r.map!() { |*x| x.first } }
call("max") { |r| r.max() { |*x| x.first } }
call("max_by") { |r| r.max_by() { |*x| x.first } }
call("member?") { |r| r.member?(1) { |*x| x.first } }
call("merge") { |r| r.merge() { |*x| x.first } }
call("min") { |r| r.min() { |*x| x.first } }
call("min_by") { |r| r.min_by() { |*x| x.first } }
call("minmax") { |r| r.minmax() { |*x| x.first } }
call("minmax_by") { |r| r.minmax_by() { |*x| x.first } }
call("none?") { |r| r.none?() { |*x| x.first } }
call("one?") { |r| r.one?() { |*x| x.first } }
call("partition") { |r| r.partition() { |*x| x.first } }
call("reduce") { |r| r.reduce() { |*x| x.first } }
call("reject") { |r| r.reject() { |*x| x.first } }
call("reject!") { |r| r.reject!() { |*x| x.first } }
call("replace") { |r| r.replace([1, 2]) { |*x| x.first } }
call("reset") { |r| r.reset() { |*x| x.first } }
call("reverse_each") { |r| r.reverse_each() { |*x| x.first } }
call("select") { |r| r.select() { |*x| x.first } }
call("select!") { |r| r.select!() { |*x| x.first } }
call("size") { |r| r.size() { |*x| x.first } }
call("slice_after") { |r| r.slice_after() { |*x| x.first } }
call("slice_before") { |r| r.slice_before() { |*x| x.first } }
call("slice_when") { |r| r.slice_when() { |*x| x.first } }
call("sort") { |r| r.sort() { |*x| x.first } }
call("sort_by") { |r| r.sort_by() { |*x| x.first } }
call("subtract") { |r| r.subtract([1, 2]) { |*x| x.first } }
call("sum") { |r| r.sum() { |*x| x.first } }
call("take") { |r| r.take(1) { |*x| x.first } }
call("take_while") { |r| r.take_while() { |*x| x.first } }
call("tally") { |r| r.tally() { |*x| x.first } }
call("to_a") { |r| r.to_a() { |*x| x.first } }
call("to_s") { |r| r.to_s() { |*x| x.first } }
call("to_set") { |r| r.to_set() { |*x| x.first } }
call("union") { |r| r.union([1, 2]) { |*x| x.first } }
call("uniq") { |r| r.uniq() { |*x| x.first } }
call("zip") { |r| r.zip() { |*x| x.first } }
call("|") { |r| r.__send__(:|, [1, 2]) { |*x| x.first } }

