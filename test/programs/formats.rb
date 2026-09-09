# Kernel#format over integers and strings, and String#%.
p format("%d", 42), format("%5d|", 42), format("%-5d|", 42), format("%05d", 42), format("%+d", 42), format("% d", 42), format("%d", -42), format("%05d", -42), format("%+05d", 42)
p format("%s", "hi"), format("%10s|", "hi"), format("%-10s|", "hi"), format("%.1s", "hi"), format("%s", :sym), format("%s", nil), format("%s", [1, 2]), format("%p", "hi"), format("%p", nil)
p format("%x", 255), format("%X", 255), format("%#x", 255), format("%o", 8), format("%#o", 8), format("%b", 5), format("%#b", 5), format("%08b", 5), format("%x", -255), format("%b", -5), format("%+x", 255), format("% x", 255)
p format("%c", 65), format("%c", "hello"), format("%%"), format("%5.2d", 3), format("%.3d", 7), format("%u", 5), format("%i", 5)
p format("%s and %s", "a", "b"), format("%2$s %1$s", "a", "b"), format("%<a>s-%<b>d", a: "x", b: 2), format("%{a}-%{b}", a: "x", b: 2), format("%*d", 5, 42), format("%-*d|", 5, 42), format("%.*d", 3, 4)
p "%d-%s" % [1, "x"], "%s" % "solo", "%05.1d" % 3, "%s" % [[1, 2]], "%<n>d" % { n: 7 }
p sprintf("%d", 3), format("%d", "12")
begin; format("%d"); rescue => e; puts "#{e.class}: #{e.message}"; end
begin; format("%d", "x"); rescue => e; puts "#{e.class}: #{e.message}"; end
begin; format("%z", 1); rescue => e; puts "#{e.class}: #{e.message}"; end
begin; format("%d %d", 1); rescue => e; puts "#{e.class}: #{e.message}"; end
begin; format("%<a>d", 1); rescue => e; puts "#{e.class}: #{e.message}"; end
begin; format("%<a>d", {}); rescue => e; puts "#{e.class}: #{e.message}"; end
begin; format("%c", -1); rescue => e; puts "#{e.class}: #{e.message}"; end
begin; format("%"); rescue => e; puts "#{e.class}: #{e.message}"; end
p format("%d", 1, 2)
p format("%-+5d|", 3), format("%x", 0), format("%#x", 0), format("%.0d", 0), format("%3s|", "abcdef"), format("%05s|", "ab"), format("%-05d|", 3)
p format("%08x", -255), format("%.6x", -255), format("%#010x", -255), format("%10x|", -255), format("%-10x|", -255), format("%+08x", -255), format("%5%"), format("%o", -8), format("%b", -1), format("%x", -1), format("%x", -16), format("%x", -17)
p 255.to_s(16), 255.to_s(2), -255.to_s(16), 0.to_s(2), 35.to_s(36), 12345.to_s(8)
begin; 1.to_s(1); rescue => e; puts "#{e.class}: #{e.message}"; end
begin; 1.to_s(37); rescue => e; puts "#{e.class}: #{e.message}"; end
printf("%d-%s\n", 1, "two")
printf
