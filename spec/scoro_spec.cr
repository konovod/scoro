require "./spec_helper"

DEBUG_LIST = [] of Int32

scoro Fiber1 do
  @i : Int32 = 0
  while @i < 3
    @i += 1
    # yield
    DEBUG_LIST << @i
  end
  @j : Int32 = @i
  if @j > @i
    while @j < 6
      @j += 1
      yield
      DEBUG_LIST << @j*10
    end
  else
    while @j < 6
      @j += 1
      yield
      DEBUG_LIST << @j*100
    end
  end
  if false
  else
    10.times do |i|
      DEBUG_LIST << i
      if i % 2 == 0
        yield
      end
    end
  end
end

describe "scoro" do
  it "runs simple example" do
    fib = Fiber1.new
    # fib.raw_run { Fiber.yield }
    fib.run
    fib.run
    DEBUG_LIST.should eq [1, 2, 3, 400]

    fib.i.should eq 3
    fib.j.should eq 5
    fib.state.should eq 11

    fib2 = Fiber1.new
    fib2.i = 3
    fib2.j = 5
    fib2.state = 11
    while !fib2.complete
      fib2.run
    end
    DEBUG_LIST.should eq [1, 2, 3, 400, 500, 600, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
  end
end

scoro FiberEach do
  [1, 10, 100].each do |x|
    DEBUG_LIST << x
    yield
  end
end

describe "scoro" do
  it "process each" do
    fib = FiberEach.new
    DEBUG_LIST.clear
    # fib.raw_run { Fiber.yield }
    fib.run
    fib.run
    fib.run
    DEBUG_LIST.should eq [1, 10, 100]
  end
end

describe "scoro" do
  it "support inline syntax" do
    fib = scoro do
      @i : Int32 = 0
      loop do
        DEBUG_LIST << @i
        @i += 1
        yield
      end
    end
    DEBUG_LIST.clear
    # fib.raw_run { Fiber.yield }
    fib.run

    fib2 = fib.dup
    fib2.run
    fib2.run
    DEBUG_LIST.should eq [0, 1, 2]
  end
end

implement_scoro
