require "./spec_helper"

DEBUG_LIST     = [] of Int32
DEBUG_STR_LIST = [] of String

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
    fib.raw_run { Fiber.yield; break if DEBUG_LIST.size >= 3 }
    DEBUG_LIST.should eq [0, 1, 2]
    DEBUG_LIST.clear
    fib.run

    fib2 = fib.dup
    fib2.run
    fib2.run
    DEBUG_LIST.should eq [0, 1, 2]
  end

  it "support return statement" do
    fib = scoro do
      @i : Int32 = 0
      loop do
        DEBUG_LIST << @i
        @i += 1
        yield
        return if @i >= 4
      end
    end
    DEBUG_LIST.clear
    while !fib.complete
      fib.run
    end
    DEBUG_LIST.should eq [0, 1, 2, 3]
  end

  it "support break and next" do
    fib = scoro do
      @i : Int32 = 0
      loop do
        @i += 1
        5.times do |i|
          next unless i == @i
          DEBUG_LIST << @i
        end
        break if @i >= 10
        yield
      end
    end
    DEBUG_LIST.clear
    while !fib.complete
      fib.run
    end
    DEBUG_LIST.should eq [1, 2, 3, 4]
  end

  it "support times without counter" do
    fib = scoro do
      @i : Int32 = 0
      5.times do
        DEBUG_LIST << 1
        yield
      end
    end
    DEBUG_LIST.clear
    while !fib.complete
      fib.run
    end
    DEBUG_LIST.should eq [1, 1, 1, 1, 1]
  end

  it "support inner loops with times" do
    fib = scoro do
      2.times do |i|
        3.times do |j|
          DEBUG_LIST << i*10 + j
          yield
        end
      end
    end
    DEBUG_LIST.clear
    while !fib.complete
      fib.run
    end
    DEBUG_LIST.should eq [0, 1, 2, 10, 11, 12]
  end

  it "support inner loops with each" do
    fib = scoro do
      [0, 10].each do |i|
        [0, 1, 2].each do |j|
          DEBUG_LIST << i + j
          yield
        end
      end
    end
    DEBUG_LIST.clear
    while !fib.complete
      fib.run
    end
    DEBUG_LIST.should eq [0, 1, 2, 10, 11, 12]
  end

  it "support uninitialized vars" do
    fib = scoro(list: ["a", "b", "c"]) do
      @list : Array(String)
      2.times do |i|
        @list.each do |item|
          DEBUG_STR_LIST << "#{item}, #{@_i1}"
          yield
        end
      end
    end

    DEBUG_STR_LIST.clear
    while !fib.complete
      fib.run
    end
    DEBUG_STR_LIST.should eq ["a, 0", "b, 0", "c, 0", "a, 1", "b, 1", "c, 1"]
  end
end

implement_scoro
