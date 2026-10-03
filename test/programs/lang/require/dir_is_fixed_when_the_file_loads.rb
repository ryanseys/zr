before = __dir__
Dir.chdir("/") { p __dir__ == before }
p File.basename(__dir__)
