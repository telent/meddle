
class Meddle::Queue 
  attr_reader :data
  def initialize
    @data=[]
  end
  def peek
    @data[0]
  end
  def pop
    @data.shift or raise "pop on empty queue"
  end
  def push(v)
    @data.push(v)
  end
end

    
       
