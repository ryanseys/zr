# Deflate writes the bytes ruby's zlib 1.3.1 writes, at every level.
# The port in rt/kernel/zlib_*.rb is held to them byte for byte: a
# short stream is shown whole, a long one by its size and crc.
require "zlib"

def show(packed) = packed.bytesize <= 48 ? packed.unpack1("H*") : "#{packed.bytesize} bytes, crc #{Zlib.crc32(packed)}"

seed = 12345
noise = Array.new(4000) { seed = (seed * 1103515245 + 12345) & 0x7fffffff; (seed >> 16) & 0xff }.pack("C*")
words = %w[alpha beta gamma delta epsilon zeta eta theta]
prose = Array.new(3000) { |i| words[(i * 7 + i / 3) % words.size] }.join(" ")

samples = {
  "empty" => "",
  "one" => "a",
  "run" => "z" * 5000,
  "prose" => prose,
  "noise" => noise,
  "mixed" => prose[0, 2000] + noise[0, 500] + prose[2000, 2000],
  "periodic" => ("abcdefghij" * 7000),
}
levels = [Zlib::DEFAULT_COMPRESSION, *0..9]
samples.each do |name, text|
  levels.each do |level|
    packed = Zlib::Deflate.deflate(text, level)
    puts "#{name} level #{level}: #{show(packed)}"
    raise "#{name} at #{level} does not round trip" unless Zlib::Inflate.inflate(packed) == text
  end
end
puts "every stream round trips"

__END__
empty level -1: 789c030000000001
empty level 0: 7801010000ffff00000001
empty level 1: 7801030000000001
empty level 2: 785e030000000001
empty level 3: 785e030000000001
empty level 4: 785e030000000001
empty level 5: 785e030000000001
empty level 6: 789c030000000001
empty level 7: 78da030000000001
empty level 8: 78da030000000001
empty level 9: 78da030000000001
one level -1: 789c4b040000620062
one level 0: 7801010100feff6100620062
one level 1: 78014b040000620062
one level 2: 785e4b040000620062
one level 3: 785e4b040000620062
one level 4: 785e4b040000620062
one level 5: 785e4b040000620062
one level 6: 789c4b040000620062
one level 7: 78da4b040000620062
one level 8: 78da4b040000620062
one level 9: 78da4b040000620062
run level -1: 789cedc13101000000c2a0de4b6f0a3fa00000000080b701b6314f58
run level 0: 5011 bytes, crc 902434172
run level 1: 7801edd03101000000c2a0de4b6f0a3f884061c0800103060c183060c0800103060c183060c0c07b60b6314f58
run level 2: 785eedd03101000000c2a0de4b6f0a3f884061c0800103060c183060c0800103060c183060c0c07b60b6314f58
run level 3: 785eedd03101000000c2a0de4b6f0a3f884061c0800103060c183060c0800103060c183060c0c07b60b6314f58
run level 4: 785eedc13101000000c2a0de4b6f0a3fa00000000080b701b6314f58
run level 5: 785eedc13101000000c2a0de4b6f0a3fa00000000080b701b6314f58
run level 6: 789cedc13101000000c2a0de4b6f0a3fa00000000080b701b6314f58
run level 7: 78daedc13101000000c2a0de4b6f0a3fa00000000080b701b6314f58
run level 8: 78daedc13101000000c2a0de4b6f0a3fa00000000080b701b6314f58
run level 9: 78daedc13101000000c2a0de4b6f0a3fa00000000080b701b6314f58
prose level -1: 127 bytes, crc 3166210056
prose level 0: 17510 bytes, crc 1092807311
prose level 1: 236 bytes, crc 2285061536
prose level 2: 219 bytes, crc 2937232005
prose level 3: 218 bytes, crc 1903287824
prose level 4: 128 bytes, crc 3292914279
prose level 5: 127 bytes, crc 3849093338
prose level 6: 127 bytes, crc 3166210056
prose level 7: 127 bytes, crc 3604344911
prose level 8: 127 bytes, crc 3604344911
prose level 9: 127 bytes, crc 3604344911
noise level -1: 4011 bytes, crc 1244356527
noise level 0: 4011 bytes, crc 894912878
noise level 1: 4011 bytes, crc 894912878
noise level 2: 4011 bytes, crc 2820242766
noise level 3: 4011 bytes, crc 2820242766
noise level 4: 4011 bytes, crc 2820242766
noise level 5: 4011 bytes, crc 2820242766
noise level 6: 4011 bytes, crc 1244356527
noise level 7: 4011 bytes, crc 2893588590
noise level 8: 4011 bytes, crc 2893588590
noise level 9: 4011 bytes, crc 2893588590
mixed level -1: 618 bytes, crc 3662414968
mixed level 0: 4511 bytes, crc 2987515650
mixed level 1: 641 bytes, crc 1839858168
mixed level 2: 631 bytes, crc 721330543
mixed level 3: 631 bytes, crc 1158113330
mixed level 4: 619 bytes, crc 898827454
mixed level 5: 618 bytes, crc 3555747363
mixed level 6: 618 bytes, crc 3662414968
mixed level 7: 618 bytes, crc 4267710049
mixed level 8: 616 bytes, crc 1649191813
mixed level 9: 616 bytes, crc 1649191813
periodic level -1: 170 bytes, crc 1038977632
periodic level 0: 70016 bytes, crc 3859861027
periodic level 1: 410 bytes, crc 3376183294
periodic level 2: 410 bytes, crc 3605897491
periodic level 3: 410 bytes, crc 3605897491
periodic level 4: 170 bytes, crc 2272149627
periodic level 5: 170 bytes, crc 2272149627
periodic level 6: 170 bytes, crc 1038977632
periodic level 7: 170 bytes, crc 4173852971
periodic level 8: 170 bytes, crc 4173852971
periodic level 9: 170 bytes, crc 4173852971
every stream round trips
