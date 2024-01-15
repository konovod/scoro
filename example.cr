require "./src/scoro"

# This will create Serializable COROutine (SCORO)
fib = scoro do
  @list : Array(String) = ["a", "b", "c"]
  10.times do |i|
    @list.each do |item|
      puts "#{item}, #{@_i1}"
      yield
    end
  end
end

# it can be `#run` sequentially (will execute until next yield)
2.times do
  fib.run
end # will print "a, 0" and "b, 0"

# its state can be saved and restored
puts fib
fib2 = fib.dup

# and then it can be resumed from point where it stopped
while !fib2.complete
  fib2.run
end # will print "c, 0","a, 1","b, 1","c, 1",...

implement_scoro # must be placed at end of file to actually implement all scoro classes
