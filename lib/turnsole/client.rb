require 'thread'
require 'turnsole/elastictrope/client'

## all the methods here are asynchronous, except for ping!
## requests are queued and dispatched by the thread here. results are queued
## into the main turnsole ui thread, and dispatched there.
module Turnsole
class Client
  include LogsStuff

  def initialize context, url
    @context = context
    @client = ElastictropeClient.new url
    @client_mutex = Mutex.new # we sometimes access client from the main thread, for synchronous calls
  end

  def url; @client.url end

  def start!
    #@thread = start_thread!
  end

  def stop!
    #@thread.kill if @thread
  end

  def pending_queue_size; @q.size end
  def num_outstanding_requests; 0 end#@q.size + @processing_queue_size end

  ## the one method in here that is synchronous---good for pinging.
  def server_info; @client_mutex.synchronize { @client.info } end

  ## returns an array of ThreadSummary objects
  def search query, num, offset
    threads = perform :search, :args => [query, num, offset] do |resp|
      resp.map { |t| ThreadSummary.new t }
    end
  end

  def threadinfo thread_id
    result = perform :threadinfo, :args => [thread_id]
    ThreadSummary.new result
  end

  ## returns an array of [MessageSummary, depth] pairs
  def load_thread thread_id
    results = perform :thread, :args => [thread_id]
    results.map { |m, depth| [MessageSummary.new(m), depth] }
  end

  def load_message message_id, mime_type_pref="text/plain"
    result = perform :message, :args => [message_id, mime_type_pref]
    Message.new result
  end

  def thread_state thread_id
    result = perform :thread_state, :args => [thread_id]
    Set.new result
  end

  def set_labels! thread_id, labels
    result = perform :set_labels!, :args => [thread_id, labels]
    ThreadSummary.new result
  end

  def set_state! message_id, state
    result = perform :set_state!, :args => [message_id, state]
    MessageSummary.new result
  end

  def set_thread_state! thread_id, state
    result = perform :set_thread_state!, :args => [thread_id, state]
    ThreadSummary.new result
  end

  def contacts_with_prefix prefix
    results = perform :contacts_with_prefix, :args => [prefix]
    results.map { |r| Person.from_string "#{r["name"]} <#{r["email"]}>" }
  end

  def async_set_labels! thread_id, labels, opts={}
    on_success = lambda { |x| opts[:on_success].call Set.new(x) } if opts[:on_success]
    perform_async :set_labels!, opts.merge(:args => [thread_id, labels], :on_success => on_success)
  end

  def async_set_state! message_id, state, opts={}
    on_success = lambda { |x| opts[:on_success].call MessageSummary.new(x) } if opts[:on_success]
    perform_async :set_state!, opts.merge(:args => [message_id, state], :on_success => on_success)
  end

  def async_set_thread_state! thread_id, state, opts={}
    on_success = lambda { |x| opts[:on_success].call Set.new(x) } if opts[:on_success]
    perform_async :set_thread_state!, opts.merge(:args => [thread_id, state], :on_success => on_success)
  end

  def async_prune_labels! opts={}
    on_success = lambda { |x| opts[:on_success].call Set.new(x) } if opts[:on_success]
    perform_async :prune_labels!, opts.merge(:on_success => on_success)
  end

  def async_load_threadinfo thread_id, opts={}
    on_success = lambda { |x| opts[:on_success].call ThreadSummary.new(x) } if opts[:on_success]
    perform_async :threadinfo, opts.merge(:args => [thread_id], :on_success => on_success)
  end

  def async_message_part message_id, part_id, opts={}
    perform_async :message_part, opts.merge(:args => [message_id, part_id])
  end

  ## some methods we relay without change
  %w(message_part raw_message send_message bounce_message count size).each do |m|
    define_method(m) { |*a| perform m.to_sym, :args => a }
  end

  ## some methods we relay and set-ify the results
  %w(contacts labels prune_labels!).each do |m|
    define_method(m) do
      perform(m.to_sym) do |resp|
        Set.new resp
      end
    end
  end

private

  def perform cmd, opts={}, &op
    f = Fiber.current
    
    req = request cmd, opts, &op
    req.callback { f.resume(req.response) }
    
    Fiber.yield
  end

  def perform_async cmd, opts={}, &op
    req = request cmd, opts, &op
    req.callback { @context.ui.enqueue :server_response, req.response, opts[:on_success] if opts[:on_success] }
    req
  end

  def request cmd, opts, &op
    @context.ui.enqueue :network_event
    req = @client.send(cmd, *opts[:args])
    req.callback { req.response = op[req.response] } if op
    req
  end

  def log; @context.log end
end
end
