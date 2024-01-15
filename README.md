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

```crystal
require "scoro"

list = ["a","b","c"]
# This will create Serializable COROutine (SCORO)

fib = scoro do
  10.times do |i|
    list.each do |item|
      puts item, i
      yield
    end
  end
# it can be `#run` sequntially (will stop at next yield)
2.times do
  fib.run 
end # will print "a" and "b"
it state can be saved and restored
puts fib

fib2 = fib.dup
# and then it can be resumed from point where it stopped
while !fib.complete
  fib.run
end # will print "c","a","b","c",...


```
more documentation is in progress


### Limitations
 - local vars won't be serialized. Don't use them to keep information between `yield`s. For example:
 ```
   i = 5
   while i > 0 
     i -= 1
     yield
   end
 ```
 won't compile, because local variable `i` is not serialized. Instead, use serialized vars:
 ```
   @i : Int32 = 5 # specifying a type is currently required
   while @i > 0 
     @i -= 1
     yield
   end
 ```
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
 I don't think they are needed for most use cases. Any exception inside scoro will bubble up to calling code.
 - yield inside general blocks is not supported. Hardcoded support added for `times`, `loop`, `each` blocks. Support for `each_with_index` and `sleep` is planned. Note that `each` argument is evaluated on every iteration, so `[1,2,3].each` isn't a good idea.
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
