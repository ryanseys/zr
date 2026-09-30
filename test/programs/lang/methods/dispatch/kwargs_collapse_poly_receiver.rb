# A braceless keyword-argument call collapses into the callee's first unfilled
# POSITIONAL parameter when no declared keyword parameter takes a key. This
# holds also when the receiver can be of more than one class. An optional
# positional gets the hash, and a required one does too.
#
# The shape is ActiveRecord::Relation#where reached off a #select that can
# return more than one class.
#
# Two more: a callee with BOTH an optional positional and a rest gives the
# hash only to the positional, and a callee with two optional positionals
# gives it only to the first.
class R
  def initialize
    @log = []
  end
  # union return -> a poly receiver for the next call in the chain
  def select(*specs)
    return [1, 2] if specs.empty?
    self
  end
  def where(condition = nil, *args)
    @log << [condition.class.to_s, args.size]
    self
  end
  def req(condition)
    @log << ["req", condition.class.to_s]
    self
  end
  def opt_only(condition = nil)
    @log << ["opt", condition.class.to_s]
    self
  end
  def kw(a: 0, b: 1)
    @log << ["kw", a, b]
    self
  end
  def mixed(first, opts = nil)
    @log << ["mixed", first.to_s, opts.class.to_s]
    self
  end
  def kwrest(**kw)
    @log << ["kwrest", kw.size]
    self
  end
  def rest_only(*args)
    @log << ["rest", args.size, args.last.class.to_s]
    self
  end
  def two_opt(a = nil, b = nil)
    @log << ["two_opt", a.class.to_s, b.class.to_s]
    self
  end
  def report
    p @log
  end
end

def poly = R.new.select(:id)

poly.where(merged_story_id: 1).report
poly.where({ merged_story_id: 1 }).report
poly.where("literal").report
poly.where.report
poly.req(k: 1).report
poly.opt_only(k: 1).report
poly.kw(a: 9).report
poly.mixed("x", k: 1).report
poly.kwrest(k: 1, j: 2).report
poly.rest_only(k: 1).report
poly.rest_only("a", k: 1).report
poly.two_opt(k: 1).report

# and the same shapes on a statically-known receiver
R.new.where(merged_story_id: 1).report
R.new.req(k: 1).report
R.new.rest_only(k: 1).report
R.new.two_opt(k: 1).report
R.new.mixed("x", k: 1).report

# a free function, the third path
def fn(condition = nil, *args)
  p [condition.class.to_s, args.size]
end
fn(k: 1)
fn("s", k: 1)
def fn2(a = nil, b = nil) = p [a.class.to_s, b.class.to_s]
fn2(k: 1)
