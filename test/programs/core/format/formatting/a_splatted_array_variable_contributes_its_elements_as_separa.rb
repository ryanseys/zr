# A splatted Array variable contributes its ELEMENTS to format/sprintf/printf,
# one argument for each conversion, not one Array argument.
args = ["a", "b"]
p format("%s%s", *args)
p sprintf("%s/%s", *args)
p format("%s%s%s", "x", *args)

nums = [1, 2, 3]
p format("%d%d%d", *nums)

mixed = ["ab", 42, 3.5]
p format("%s%d%.1f", *mixed)

fmt = "%s-%s"
p format(fmt, *args)

printf("%s|%s\n", *args)
$stdout.printf("%s;%s\n", *args)

path = "/tmp/spinel_format_splat_test.txt"
File.open(path, "w") { |f| f.printf("%s=%s\n", *args) }
p File.read(path)
File.delete(path)

# an empty splat leaves a format with no conversions alone
none = []
p format("plain", *none)
