
class Meddle::Agent
  def add_session(session,delay=0)
    @sessions.push [session,delay]
  end

  def initialize(options={})
    @connections_per_host=options[:connections_per_host] || 2
    @sessions=[]
    yield(self)
    now=Time.now
    @sessions.each do |sess,delay|
      queue=Hash.new {|hash,k| hash[k]=Meddle::Queue.new }
      sess.each do |tx|
        host=URI.parse(tx.request.uri).host
        queue[host].push [now+(tx.start_time-sess[0].start_time)+delay,tx]
      end
      queue.keys.each do |host|
        @connections_per_host.times do |c|
          Meddle::Connection.start(queue[host])
        end
      end
    end      
  end
end
