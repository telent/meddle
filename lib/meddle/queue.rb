
class Meddle::Queue 
  attr_reader :data
  def initialize
    @data=[]
  end
  def peek
    @data[0]
  end
  def pop(default=nil)
    @data.shift or default
  end
  def push(v)
    @data.push(v)
  end
end

    
       
