
# extends EM::Queue with a #peek method

class Meddle::Queue < EM::Queue
  def peek
    v=self.pop
    self.push(v)
    v
  end
end

    
       
