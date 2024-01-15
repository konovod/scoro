# Results in debug mode:
#
# d:\projects\crystal\scoro>crystal benchmark.cr
# Warning: benchmarking without the `--release` flag won't yield useful results
#                     direct code  12.49k ( 80.05µs) (± 2.07%)  0.0B/op        fastest
#  native coroutine without yield  12.24k ( 81.67µs) (± 2.36%)  144B/op   1.02× slower
#     native coroutine with yield 178.14  (  5.61ms) (± 2.35%)  188B/op  70.13× slower
# serialized coroutine with yield 170.74  (  5.86ms) (± 1.96%)  255B/op  73.17× slower
#
# Results in release mode:
# d:\projects\crystal\scoro>crystal run --release benchmark.cr
#                     direct code  87.25k ( 11.46µs) (± 2.03%)  0.0B/op         fastest
#  native coroutine without yield  84.61k ( 11.82µs) (± 1.72%)  144B/op    1.03× slower
#     native coroutine with yield 742.03  (  1.35ms) (± 1.85%)  193B/op  117.58× slower
# serialized coroutine with yield 711.89  (  1.40ms) (± 1.87%)  256B/op  122.55× slower

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
