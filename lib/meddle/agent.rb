
class Meddle::Agent
  def add_session(session,delay=0)
    @sessions.push [session,delay]
  end

  def initialize(options)
    @connections_per_host=options[:connections_per_host] || 2
    @sessions=[]
    yield(self)
    now=Time.now
    @sessions.each do |sess,delay|
      queue=Hash.new {|hash,k| hash[k]=[] }
      sess_orig_start=sess[0].start_time
      sess.each do |tx|
        host=URI.parse(tx.request.uri).host
        queue[host] << [now+tx.start_time-sess[0].start_time+delay,tx]
      end
      @connections_per_host.times do |c|
        Connection.start(queue)
      end
    end      
  end
end
