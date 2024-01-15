# scoro

Serializable COROutines in a Crystal (white-box state machine approach)

Works by unrolling language constructions to one state machine

It will be impossible without 
  Idea: https://gamedev.ru/flame/forum/?id=238878&page=35&m=5849512#m510
  Way to make `while` loop inside a macro: https://github.com/crystal-lang/crystal/pull/10959#issuecomment-882036815

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     scoro:
       github: konovod/scoro
   ```

2. Run `shards install`

## Usage

### Simple example
```crystal
require "scoro"

LIST = ["a", "b", "c"]

# This will create Serializable COROutine (SCORO)
fib = scoro do
  10.times do |i|
    LIST.each do |item|
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
```

### Named scoros
```crystal
require "scoro"

LIST = ["a", "b", "c"]

# This will declare class Fiber1 with a Serializable COROutine (SCORO)
scoro(Fiber1) do
  10.times do |i|
    LIST.each do |item|
      puts "#{item}, #{@_i1}"
      yield
    end
  end
end

# it can be instanciated and then used:
fib = Fiber1.new
while !fib.complete
  fib.run
end

implement_scoro # must be placed at end of file to actually implement all scoro classes
```
### Local vars

local vars won't be saved in a scoro. So they can be only inside one state (between `yield`s).

```
scoro(Fiber1) do
  loop do
    a = 1 # var usage is limited to one state
    10.times do |i|
      a += 1
    end
    puts a # this will compile, because `a` is defined in same state as used
    yield
    # puts a <- compilation error, because `a` isn't serialized and can be undefined at this point
  end
end
```

To solve it, use serialized vars (instance vars of scoro class). They can be defined as following:

```
scoro(Fiber1) do
  loop do
    @a : Int32 = 1 # instance var, can be used in any states
    10.times do |i|
      @a += 1
      yield
    end
    yield
    puts @a
  end
end
```

### Passing arguments to scoros

Note first example used constant `LIST` instead of local var `list` because scoros do not capture local vars.
To pass arguments to scoro you can use serialized vars without initial value:

```
  fib = scoro(list: ["a", "b", "c"]) do
    @list : Array(String) # declares serialized var without initial value. Note list is passed as named argument when creating fiber
    2.times do |i|
      @list.each do |item|
        puts "#{item}"
        yield
      end
    end
  end

  fib.run  
```
or for the named scoros:
```
scoro FiberWithList do
  @list : Array(String)
  @list.each do |item|
    puts item
    yield
  end
end

# fib = FiberWithList.new <- this won't compile
fib = FiberWithList.new(list: ["a","b","c"])
```

### Blocks

In general, yields inside blocks can't be serialized:
```
scoro MyFiber do
  thrice do |item| # what is contained inside function `thrice` is unknown to a scoro library, so it's state can't be serialized
    puts item
    yield
  end
end
```

All above examples used blocks though and compile. Why? Because calls of `times`, `each`, `loop` are hardcoded in a library.
`loop`: simplest, equivalent to `while true...`, no serialized state
`n.times`: equivalent to `i=0; while i<n...`, has internal state of one Int32 var
`list.each do |item|`: rewritten `i=0; while i<n; item=list[i]...`, has internal state of one Int32 var

### Actual serialization
ok, all of this is nice, but how to actually Serialize coroutne state! 
All generated scoro classes are inherited from `SerializableCoroutine`
You can `include JSON::Serializable` or `include YAML::Serializable` or add other serialization method of your choice to it.
If you use named scoro, you can also reopen its class to add needed methods.

```
require "scoro"
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
```


## Limitations
 - currently, type of serialized vars must be always specified explicitly
 - currently, serialized vars can be declared only on top level.
  This example won't compile:
 ```
   while some_action_required
    @i : Int32 = 5
    while @i > 0 
      @i -= 1
      yield
    end
   else  
   end
 ```
 Fix it so:
 ```
   @i : Int32 = 0
   while some_action_required
    @i = 5
    while @i > 0 
      @i -= 1
      yield
    end
   end
 ```
 - ensure\rescue blocks are not supported. 
 I don't think they are needed for most use cases. Any exception inside scoro will just propagate to calling code.
 - yield inside general blocks is not supported. Hardcoded support added for `times`, `loop`, `each` blocks. Support for `each_with_index` and `sleep` is planned. 
 - `each` caller is evaluated on every iteration, so `[1,2,3].each` inside scoro isn't a good idea (will allocate new array every time scoro is resumed).
 - `each` only work with `Indexable`, not `Enumerable`, because state of `Indexable` iteration can be easily serialized - it's just index
 - for now, all control constructs (`next`\`break`\`return`) unrolls involved loops to state machine even if there is no `yield` inside loop. 
 
## Development

 - [x] BUG: update all variables for inner loops
 - [x] FEATURE: pass arguments to anonymous scoros
 - [ ] OPTIMIZATION: merge loop start with loop control state
 - [ ] OPTIMIZATION: don't mark all ControlExpressions as dirty (separate pass?)
 - [ ] FEATURE: sleep
 - [ ] FEATURE: channel.send\receive?
 - [ ] FEATURE: each_with_index



## Contributing

1. Fork it (<https://github.com/konovod/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [konovod](https://github.com/konovod) - creator and maintainer
