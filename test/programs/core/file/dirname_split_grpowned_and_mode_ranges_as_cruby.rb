# dirname keeps the separators inside what it returns; split converts
# its path once; a mode out of range raises RangeError; grpowned? counts
# the effective group.
%w[/home/jason /holy///schnikies//w00t.bin poot.txt / // ////// //foo// ./b/./ /foo/../. /. .. ../ a//b// /a/b/c].each do |x|
  p [x, File.dirname(x), File.dirname(x, 2)]
end
s = Object.new
def s.to_str = (($k ||= 0); $k += 1; "/a/b")
p File.split(s), $k
p((File.umask(2**64) rescue $!), (File.umask(-2**63 - 1) rescue $!), (File.chmod(-2**63 - 1, __FILE__) rescue $!))
p File.grpowned?(__FILE__), File.stat(__FILE__).grpowned?, File.grpowned?("/nonexistent/zr")
