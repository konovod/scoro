# supported constructs:
# +Case
# +If [branch1, branch2 inc at branch start]
# +While [(start, end), inc at start and end]
# +Yield [(after), inc at after]
# +TypeDeclaration
# Call: +each, +times, +loop, -sleep [rewrite to while] [others - fail]
# +Break [just adds @state= and next iteration]
# +Next [adds @state=, inc if needed and next iteration]
# +Return [adds @complete= and return]
# -ExceptionHandler [possible, but not planned]

# Require setting local_vars: :yield, :while, :transition, :end_times, :if

private IMPL_BLOCKS         = {} of MacroId => ASTNode
private UNNAMED_IMPL_BLOCKS = [0]

private SCORO_DEBUG = false # set to true to see generated code

abstract class SerializableCoroutine
  property state = 0
  property complete = false

  abstract def raw_run(&)
  abstract def run
end

macro scoro(**args, &block)
  {%
    UNNAMED_IMPL_BLOCKS[0] += 1
    name = "ScoroTempClass#{UNNAMED_IMPL_BLOCKS[0]}".id
    IMPL_BLOCKS[name] = block
  %}
  {{name}}.new({{**args}})
end

macro scoro(class_name, &block)
  {%
    IMPL_BLOCKS[class_name] = block
  %}
end

macro implement_scoro
  {% for class_name, block in IMPL_BLOCKS %}
  class {{class_name}} < SerializableCoroutine
    {% init_vars = [] of MacroId %}
    {% if block.body.is_a? Expressions %}
    {% for expr in block.body.expressions %}
      {% if expr.is_a? TypeDeclaration %}
        {% if expr.value.is_a? Nop %}
        {{expr.var}} : {{expr.type}}
         {% init_vars << expr.var %}
        {% else %}
        {{expr.var}} = uninitialized {{expr.type}} # assignment will happen in a coroutine
        {% end %}

        def {{expr.var.stringify.gsub(/@/, "").id}}=(value)
          {{expr.var}} = value
        end
        def {{expr.var.stringify.gsub(/@/, "").id}}
          {{expr.var}}
        end
      
      {% if init_vars.size > 0 %}  
        def initialize({{init_vars.join(", ").id}})
        end
      {% end %}

      {% end %}
    {% end %}
    {% end %}

    def raw_run(&)
      {% if block.body.is_a? Expressions %}
      {% for expr in block.body.expressions %}
      {% if expr.is_a? TypeDeclaration %}
        {% unless expr.value.is_a? Nop %}
          {{expr.var}} = {{expr.value}}
        {% end %}  
      {% else %}  
        {{expr}}
      {% end %}
      {% end %}
      {% else %}
        {{yield}}
      {% end %}
    end

          {% dirty = {} of Tuple(ASTNode, NumberLiteral) => Bool

             # ---find yields, mark constructs that is 'dirty'

             forever = [nil] of NilLiteral
             queue = [block.body]
             parents_stack = [] of ASTNode
             supported_calls = {"times" => true, "each" => true, "loop" => true}

             forever.each do
               forever << nil
               expr = queue.first
               if expr.is_a?(NilLiteral)
                 forever.clear
               else
                 queue = queue[1..-1]
                 if expr.is_a? While
                   parents_stack << expr
                   queue = [expr.body, 1] + queue
                 elsif expr.is_a? Call
                   if expr.block.is_a? Block
                     parents_stack << expr
                     queue = [expr.block.body, 1] + queue
                   end
                 elsif expr.is_a? If
                   parents_stack << expr
                   queue = [expr.then, expr.else, 1] + queue
                 elsif expr.is_a? Case
                   parents_stack << expr
                   queue = expr.whens.map(&.body) + [expr.else, 1] + queue
                 elsif expr.is_a?(Yield) || expr.is_a?(ControlExpression)
                   # found yield, mark all parents as dirty
                   parents_stack.each do |marked|
                     dirty[{marked, marked.line_number, marked.column_number}] = true
                   end
                 elsif expr.is_a? Expressions
                   # no interesting nodes, just replace with items
                   queue = expr.expressions + queue
                 elsif expr.is_a? NumberLiteral
                   # end of parent
                   last = parents_stack.last
                   if last.is_a?(Call) && !supported_calls[last.name.stringify]
                     raise "Yielding in block is not supported for method #{last.name}, only #{supported_calls.keys} are supported"
                   end
                   parents_stack = parents_stack[0...-1]
                 elsif expr.is_a? ExceptionHandler
                   raise "ensure/except blocks are not supported"
                 else
                   # puts(expr.class_name)
                   # skip all other nodes
                 end
               end
             end

             #  puts dirty.keys.map(&.first.class_name)

             forever = [nil] of NilLiteral
             queue = [block.body]
             cur_state = 0

             gen_list = [] of Tuple(Symbol | ASTNode, Int32)
             add_vars_count = 0
             cur_loop_stack = [] of Tuple(Int32, Int32?)
             local_vars = [] of Tuple(StringLiteral, StringLiteral)

             forever.each do
               forever << nil
               expr = queue.first
               if expr.is_a?(NilLiteral)
                 forever.clear
               else
                 queue = queue[1..-1]
                 if expr.is_a? Expressions
                   # no interesting nodes, just replace with items
                   queue = expr.expressions + queue
                 elsif expr.is_a? Nop
                   # just skip
                 elsif expr.is_a? TupleLiteral
                   # end of some expression
                   first, second, third = expr
                   if first.is_a? While
                     cur_loop_stack = cur_loop_stack[0...-1]
                     gen_list << [:transition, second, second + 2]
                     #  dump local vars assignments
                     local_vars.each { |tuple| gen_list << [:assign, tuple[0], tuple[1]] }
                   elsif first.is_a? Call
                     cur_loop_stack = cur_loop_stack[0...-1]
                     if first.name == "times"
                       gen_list << [:end_times, second, third]
                       local_vars = local_vars[0...-1]
                       #  dump local vars assignments
                       local_vars.each { |tuple| gen_list << [:assign, tuple[0], tuple[1]] }
                     elsif first.name == "each"
                       gen_list << [:end_times, second, third]
                       local_vars = local_vars[0...-1]
                       #  dump local vars assignments
                       local_vars.each { |tuple| gen_list << [:assign, tuple[0], tuple[1]] }
                     elsif first.name == "loop"
                       gen_list << [:transition, second, second + 2]
                       #  dump local vars assignments
                       local_vars.each { |tuple| gen_list << [:assign, tuple[0], tuple[1]] }
                     end
                   elsif first.is_a? If
                     if third == 0
                       gen_list << [:transition, second + 2, second + 1]
                     else
                       gen_list << [:transition, second + 2, second + 2]
                     end
                     #  dump local vars assignments
                     local_vars.each { |tuple| gen_list << [:assign, tuple[0], tuple[1]] }
                   elsif first.is_a? Case
                     gen_list << [:transition, third, second]
                     #  dump local vars assignments
                     local_vars.each { |tuple| gen_list << [:assign, tuple[0], tuple[1]] }
                   else
                     raise "BUG: unsupported node: #{expr}"
                   end
                 elsif expr.is_a? Yield
                   # found yield, mark all parents as dirty
                   cur_state += 1
                   gen_list << [:yield, cur_state]
                   #  dump local vars assignments
                   local_vars.each { |tuple| gen_list << [:assign, tuple[0], tuple[1]] }
                 elsif expr.is_a? TypeDeclaration
                   unless expr.value.is_a? Nop
                     gen_list << [:assign, expr.var, expr.value]
                   end
                 elsif expr.is_a? Return
                   gen_list << [:return, cur_state]
                 elsif expr.is_a? Break
                   last_loop = cur_loop_stack.last
                   gen_list << [:next, last_loop[0] + 2]
                 elsif expr.is_a? Next
                   last_loop = cur_loop_stack.last
                   if last_loop[1].is_a? NumberLiteral
                     gen_list << [:next_inc, cur_loop_stack.last[0], cur_loop_stack.last[1]]
                   else
                     gen_list << [:next, cur_loop_stack.last[0]]
                   end
                 elsif !dirty[{expr, expr.line_number, expr.column_number}]
                   gen_list << [expr, nil]
                 elsif expr.is_a? While
                   cur_state += 1
                   cur_loop_stack << {cur_state, nil}
                   gen_list << [:while, cur_state, expr.cond]
                   queue = [expr.body, {expr, cur_state}] + queue
                   cur_state += 2
                   #  dump local vars assignments
                   local_vars.each { |tuple| gen_list << [:assign, tuple[0], tuple[1]] }
                 elsif expr.is_a? Call
                   cur_state += 1
                   if expr.name == "times"
                     add_vars_count += 1
                     cur_loop_stack << {cur_state, add_vars_count}
                     gen_list << [:assign, "@_i#{add_vars_count}".id, 0]
                     gen_list << [:while, cur_state, "@_i#{add_vars_count} < #{expr.receiver}".id]
                     local_vars << [expr.block.args[0], "@_i#{add_vars_count}".id] unless expr.block.args.empty?
                     #  dump local vars assignments
                     local_vars.each { |tuple| gen_list << [:assign, tuple[0], tuple[1]] }
                     queue = [expr.block.body, {expr, cur_state, add_vars_count}] + queue
                   elsif expr.name == "loop"
                     cur_loop_stack << {cur_state, nil}
                     gen_list << [:while, cur_state, true]
                     #  dump local vars assignments
                     local_vars.each { |tuple| gen_list << [:assign, tuple[0], tuple[1]] }
                     queue = [expr.block.body, {expr, cur_state}] + queue
                   elsif expr.name == "each"
                     add_vars_count += 1
                     cur_loop_stack << {cur_state, add_vars_count}
                     gen_list << [:assign, "@_i#{add_vars_count}".id, 0]
                     gen_list << [:while, cur_state, "@_i#{add_vars_count} < #{expr.receiver}.size".id]
                     local_vars << [expr.block.args[0], "#{expr.receiver}[@_i#{add_vars_count}]".id]
                     #  dump local vars assignments
                     local_vars.each { |tuple| gen_list << [:assign, tuple[0], tuple[1]] }
                     queue = [expr.block.body, {expr, cur_state, add_vars_count}] + queue
                   end
                   cur_state += 2
                 elsif expr.is_a? If
                   cur_state += 1
                   gen_list << [:if, cur_state, expr.cond]
                   queue = [expr.then, {expr, cur_state, 0}, expr.else, {expr, cur_state, 1}] + queue
                   cur_state += 2
                   #  dump local vars assignments
                   local_vars.each { |tuple| gen_list << [:assign, tuple[0], tuple[1]] }
                 elsif expr.is_a? Case
                   cur_state += 1
                   if expr.exhaustive?
                     gen_list << [:case_exhaustive, cur_state, expr.cond, expr.whens.map(&.conds)]
                   else
                     gen_list << [:case, cur_state, expr.cond, expr.whens.map(&.conds), !expr.else.is_a?(Nop)]
                   end
                   #  dump local vars assignments
                   local_vars.each { |tuple| gen_list << [:assign, tuple[0], tuple[1]] }
                   n = expr.whens.size
                   n += 1 unless expr.else.is_a? Nop
                   list = [] of ASTNode
                   expr.whens.each_with_index do |awhen, i|
                     list << awhen.body << {expr, cur_state + i + 1, cur_state + n}
                   end
                   unless expr.else.is_a? Nop
                     list << expr.else << {expr, cur_state + n, cur_state + n}
                   end
                   queue = list + queue
                   cur_state += n
                 else
                   raise "BUG: unsupported node: #{expr}"
                 end
               end
             end %}

           {% for i in 1..add_vars_count %}
             property _i{{i}} = 0
           {% end %}
       

      def run
      return if @complete
      loop do
        case @state
        when 0

  {% for expr in gen_list %}
    {% if expr[0] == :assign %}
            {{expr[1]}} = {{expr[2]}}
    {% elsif expr[0] == :yield %}
            @state = {{expr[1]}}
            return
        when {{expr[1]}}
    {% elsif expr[0] == :while %}
            @state = {{expr[1]}}
        when {{expr[1]}}
            if {{expr[2]}}
              @state = {{expr[1] + 1}}
            else
              @state = {{expr[1] + 2}}
            end  
        when {{expr[1] + 1}}
    {% elsif expr[0] == :transition %}
          @state = {{expr[1]}}
        when {{expr[2]}}
    {% elsif expr[0] == :end_times %}
          @_i{{expr[2]}} += 1
          @state = {{expr[1]}}
        when {{expr[1] + 2}}
    {% elsif expr[0] == :if %}
          if {{expr[2]}}
            @state = {{expr[1]}}
          else
            @state = {{expr[1] + 1}}
          end  
        when {{expr[1]}}
    {% elsif expr[0] == :return %}
          @complete = true
          return
    {% elsif expr[0] == :next %}
          @state = {{expr[1]}}
          next
    {% elsif expr[0] == :next_inc %}
          @_i{{expr[2]}} += 1
          @state = {{expr[1]}}
          next
    {% elsif expr[0] == :case_exhaustive %}
            case {{expr[2]}}
            {% for conds, i in expr[3] %}
            in {{conds.join(", ").id}} 
              @state = {{expr[1] + i}}
            {% end %}
            end  
        when {{expr[1]}}
    {% elsif expr[0] == :case %}
            case {{expr[2]}}
            {% for conds, i in expr[3] %}
            when {{conds.join(", ").id}} 
              @state = {{expr[1] + i}}
            {% end %}
            else
              @state = {{expr[1] + expr[3].size}}
            end  
        when {{expr[1]}}
    {% else %}
          {{expr[0]}}
    {% end %}
  {% end %}
          @state += 1
          @complete = true
          return # fiber complete
        end
      end
      if false #to perform syntax check of initial code
        raw_run{}
      end
    end
  end
{% end %}
{%
  IMPL_BLOCKS.clear
  if SCORO_DEBUG
    debug
  end
%}
end
