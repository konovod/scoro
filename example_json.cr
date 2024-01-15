require "./src/scoro"
require "json"

class SerializableCoroutine
  include JSON::Serializable
end

fib = scoro(list: ["a", "b", "c"]) do
  @list : Array(String)
  2.times do |i|
    @list.each do |item|
      puts "#{item}"
      yield
    end
  end
end

fib.run
puts fib.to_json

fib2 = typeof(fib).from_json(fib.to_json)
fib2.run

implement_scoro
