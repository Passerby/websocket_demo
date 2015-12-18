require 'em-websocket'
require 'multi_json'

module EventMachine
  module WebSocket
    def self.start(options, &blk)
      EM.epoll? ? EM.epoll : EM.kqueue
      EM.run {
        trap("TERM") { stop }
        trap("INT")  { stop }

        run(options, &blk)
      }
    end
  end
end

class WebsocketServer
  include EventMachine::WebSocket::Debugger
  def initialize(options = {})
    @options = options
    @channels = {}
  end

  def run
    EM.run {
      EM::WebSocket.start(@options) do |ws|
        ws.onopen { |handshake|
          puts "WebSocket connection open"

          # Access properties on the EM::WebSocket::Handshake object, e.g.
          # path, query_string, origin, headers

          # Publish message to the client
          ws.send "Hello Client, you connected to #{handshake.path}"
          ws.send "Ping supported: #{ws.pingable?}"

          # 30 秒一次心跳 ping
          EventMachine.add_periodic_timer(30) { ws.ping 'Hi' }
        }

        ws.onclose { debug [:onerror, "Connection closed"] }

        ws.onmessage { |msg|
          debug [:onmessage, msg]
          begin
            data = MultiJson.load(msg)

            # 事件处理
            case data["event"]
            when 'huanteng_pusher:subscribe' # 订阅频道
              if sid = subscribe_channel(ws, data['channel'], data['auth'])
                ws.send(MultiJson.dump({ event: 'huanteng_pusher:subscribe_successed', sid: sid, channel: data['channel'], auth: ['auth'] }))
              else
                # TODO 推送失败信息
              end
            when 'huanteng_pusher:unsubscribe' # 取消订阅
              ws.send(MultiJson.dump( event: 'huanteng_pusher:unsubscribe_successed', result: unsubscribe_channel(data['sid'])))
            when 'huanteng_pusher:trigger' # 幻腾触发
              trigger(data['channel'], data['event'], data['data'], data['access_token'])
              ws.send(MultiJson.dump( event: 'huanteng_pusher:trigger', result: 'success' ))
            else
              ws.send(MultiJson.dump({ event: 'unknow', data: msg }))
            end
          rescue Exception => e
            debug [:onmessage, e.to_s]
          end
        }

        ws.onpong { |value| debug [:onpong, "Received pong: #{value}"] }
        ws.onping { |value| debug [:onping, "Received ping: #{value}"] }
        ws.onerror { |e| debug [:onerror, "Error: #{e.message}"] }
      end
    }
  end

  def authenticate!(access_token)
    # TODO 验证方式
    # access_token 可以存在 redis, 每次就可以直接从 redis 验证用户
    # 设置 user_id redis.set("app_id/#{app_id}/#{access_token[:access_token]}/#{access_token[:device_id]}/#{access_token[:user_agent]}", access_token.user_id)
    # 设置 access_token 过期时间 redis.expire_at("app_id/#{app_id}/#{access_token[:access_token]}/#{access_token[:device_id]}/#{access_token[:user_agent]}", access_token.expired_at.to_i)
    true
  end

  def subscribe_channel(ws, channel, access_token)
    return unless authenticate!(access_token)
    if @channels[channel].nil?
      @channels[channel] = EventMachine::Channel.new
    end
    # TODO sid 和 websocket connection 作对应关系
    # TODO Channel 需要封装， 增加 ws 传递
    @channels[channel].subscribe(ws, :send)
  end

  def unsubscribe_channel(sid, access_token)
    # TODO 找到 sid 和 websocket connection 作对应关系
    return if !authenticate!(access_token) || @channels[channel].nil?
    @channels[channel].unsubscribe(sid)
  end

  def trigger(channel, event, data, trigger_access_token)
    # TODO 触发 trigger_access_token 验证
    if @channels[channel].nil?
      @channels[channel] = EventMachine::Channel.new
    end
    @channels[channel] << MultiJson.dump(channel: channel, event: event, data: data)
  end
end

WebsocketServer.new(host: "0.0.0.0", port: 8080, debug: true).run
# 客户端监听 { "event": "huanteng_pusher:subscribe", "auth": "asdsdsadsadsad", "channel": "presence-DoorSensorsChanged-v1-1392186763" }
# 服务器触发 { "event": "huanteng_pusher:trigger", "channel": "presence-DoorSensorsChanged-v1-1392186763", "data": "trigger you", "access_token": "access_token" }
