
class Meddle::Agent
  def add_session(session,delay=0)
    session.agent=self
    @sessions.push [session,delay]
  end
  attr_accessor :finish_time
  def initialize(options={})
    @connections_per_host=options[:connections_per_host] || 2
    @sessions=[]
    yield(self)
    now=Time.now
    @finish_time=now
    @sessions.each do |sess,delay|
      queue=Hash.new {|hash,k| hash[k]=Meddle::Queue.new }
      sess.each do |tx|
        host=tx.request.uri.host
        tx_time=now+(tx.start_time-sess[0].start_time)+delay
        queue[host].push [tx_time,tx]
        if tx_time > @finish_time then @finish_time=tx_time end
      end
      queue.keys.each do |host|
        @connections_per_host.times do |c|
          Meddle::Connection.start(queue[host],sess)
        end
      end
    end      
  end
end
