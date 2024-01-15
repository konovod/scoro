# Results in debug mode:
#
# d:\projects\crystal\scoro>crystal run benchmark.cr
# Warning: benchmarking without the `--release` flag won't yield useful results
#                        direct code  13.65k ( 73.28µs) (± 0.72%)   0.0B/op        fastest
#     native coroutine without yield  13.42k ( 74.50µs) (± 1.69%)   144B/op   1.02× slower
# serialized coroutine without yield   4.06k (246.31µs) (± 0.71%)  32.0B/op   3.36× slower
#        native coroutine with yield 194.40  (  5.14ms) (± 0.83%)   189B/op  70.20× slower
#    serialized coroutine with yield 186.99  (  5.35ms) (± 0.76%)   259B/op  72.98× slower
#
# d:\projects\crystal\scoro>crystal run --release benchmark.cr
#                        direct code  96.43k ( 10.37µs) (± 0.86%)   0.0B/op         fastest
#     native coroutine without yield  93.84k ( 10.66µs) (± 0.58%)   144B/op    1.03× slower
# serialized coroutine without yield  23.62k ( 42.34µs) (± 6.04%)  32.0B/op    4.08× slower
#        native coroutine with yield 809.14  (  1.24ms) (± 0.52%)   191B/op  119.17× slower
#    serialized coroutine with yield 762.11  (  1.31ms) (± 1.85%)   256B/op  126.53× slower

require "benchmark"
require "./src/scoro"

N = 10000

done = Channel(Nil).new

Benchmark.ips do |bench|
  bench.report("direct code") do
    sum = 0
    N.times { |i| sum += i % 19 }
  end

  bench.report("native coroutine without yield") do
    spawn do
      sum = 0
      N.times { |i| sum += i % 19 }
      done.send(nil)
    end
    done.receive
  end

  bench.report("serialized coroutine without yield") do
    sc = scoro do
      @sum : Int32 = 0
      N.times { |i| @sum += i % 19; yield }
    end
    while !sc.complete
      sc.run
    end
  end

  bench.report("native coroutine with yield") do
    spawn do
      sum = 0
      N.times { |i| sum += i % 19; Fiber.yield }
      done.send(nil)
    end
    done.receive
  end

  bench.report("serialized coroutine with yield") do
    sc = scoro do
      @sum : Int32 = 0
      N.times { |i| @sum += i % 19; yield }
    end
    spawn do
      while !sc.complete
        sc.run
        Fiber.yield
      end
      done.send(nil)
    end
    done.receive
  end
end

implement_scoro
