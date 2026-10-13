# Range#include? as range_include_internal decides it: numbers and Times
# cover, two Strings compare, anything else iterates, a range open at
# both ends takes any number or Time, and one open end refuses the rest.
# reverse_each's size names the end that no walk can start from, and
# max(n) takes the first n of reverse_each, so a huge range answers at once.
$stdout.sync = true
def try(label)
  p [label, yield]
rescue => e
  p [label, e.class, e.message]
end

class Step
  include Comparable
  attr_reader :v
  def initialize(v) = @v = v
  def succ = Step.new(@v + 1)
  def <=>(other) = other.is_a?(Step) ? @v <=> other.v : nil
end

try(:both_open_int) { (nil..nil).include?(1) }
try(:both_open_float) { (nil..nil).include?(1.0) }
try(:both_open_rational) { (nil..nil).include?(1r) }
try(:both_open_complex) { (nil..nil).include?(Complex(1)) }
try(:both_open_time) { (nil..nil).include?(Time.at(0)) }
try(:both_open_string) { (nil..nil).include?("a") }
try(:both_open_object) { (nil..nil).include?(Object.new) }
try(:endless_step) { (Step.new(1)..).include?(Step.new(2)) }
try(:beginless_step) { (..Step.new(3)).include?(Step.new(2)) }
try(:closed_step) { (Step.new(1)..Step.new(3)).include?(Step.new(2)) }
try(:endless_string) { ("a"..).include?("b") }
try(:string_and_int) { ("a"..5).include?("b") }
try(:member) { (nil..nil).member?(2) }
try(:time_range) { (Time.at(0)..Time.at(10)).include?(Time.at(5)) }

{ "1.1..3" => (1.1..3), "1.1..3.3" => (1.1..3.3), "1.1.." => (1.1..nil), "..3.3" => (nil..3.3), "nil..nil" => (nil..nil),
  "1..3" => (1..3), "1..3.5" => (1..3.5), "..3" => (nil..3), "1.." => (1..nil), "a..c" => ("a".."c"),
  "step" => (Step.new(1)..Step.new(3)), "time" => (Time.at(0)..Time.at(1)) }.each do |label, r|
  try([:reverse_size, label]) { r.reverse_each.size }
end

try(:max_huge) { (0...2**64).max(2) }
try(:max_beginless) { (..10).max(3) }
try(:max_zero) { (1..5).max(0) }
try(:max_more) { (1..3).max(5) }
try(:max_excl) { (1...4).max(2) }
try(:max_float) { (303.20..908.1111).max(2) }
try(:max_beginless_float) { (..3.5).max(2) }
try(:max_strings) { ("a".."e").max(2) }
try(:max_negative) { (1..3).max(-1) }
