# A block at the top level of a required file is in no method, so
# __method__ is nil wherever it runs.
require_relative "method_name_in_a_required_file/lib"
class Runner
  def to_a(b) = b.call
  def yy = yield
end
p Runner.new.to_a(BLK), Runner.new.yy(&BLK), BLK.call, BLK2.call
p lib_def
