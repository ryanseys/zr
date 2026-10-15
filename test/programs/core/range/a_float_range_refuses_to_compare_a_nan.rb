# ruby compares two Floats with rb_float_cmp, which refuses a NaN, so a
# Range of Floats raises ArgumentError for it in ===, cover?, include?
# and member?, and in a `when`. A Range with an Integer end compares
# through <=>, whose nil means "not covered".
nan = Float::NAN

def try(label)
  p [label, yield]
rescue ArgumentError => e
  puts "#{label}: #{e.message}"
end

try("===") { (0.0..5.0) === nan }
try("cover?") { (0.0..5.0).cover?(nan) }
try("include?") { (0.0..5.0).include?(nan) }
try("member?") { (0.0..5.0).member?(nan) }
try("exclusive") { (0.0...5.0) === nan }
try("endless") { (0.0..) === nan }
try("beginless") { (..5.0) === nan }
try("beginless exclusive") { (...5.0).include?(nan) }
try("infinite") { (-Float::INFINITY..Float::INFINITY) === nan }
try("integer begin") { (0..5.0) === nan }
try("integer end") { (0.0..5) === nan }
try("integer range") { (0..5) === nan }
try("integer range cover?") { (0..5).cover?(nan) }
try("nan begin") { (nan..1.0) rescue $!.message }
try("range in range") { (0.0..5.0).cover?(1.0..nan) rescue $!.message }
try("when") do
  case nan
  when 0.0..5.0 then :in
  else :out
  end
end
try("grep") { [0.0, 5.0, nan].grep(0.0..5.0) }
try("grep before nan") { [0.0, 5.0].grep(0.0..5.0) }
try("in range") { [(0.0..5.0).cover?(2.0), (0.0..5.0) === 5.0, (0.0...5.0) === 5.0, (..5.0) === -1e300] }
