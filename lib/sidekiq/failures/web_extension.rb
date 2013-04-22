module Sidekiq
  module Failures
    module WebExtension

      def self.registered(app)
        app.get "/failures" do
          view_path = File.join(File.expand_path("..", __FILE__), "views")
          @filter = params["filter"]

          @count = (params[:count] || 25).to_i
          (@current_page, @total_size, @messages) = WebExtension.page_with_query("failed", params[:page], @count, @filter)

          @messages = @messages.map { |msg| Sidekiq.load_json(msg) } if @messages

          @paging = File.read(File.join(view_path, "_paging_failures.slim"))

          render(:slim, File.read(File.join(view_path, "failures.slim")))
        end

        app.post "/failures/remove" do
          Sidekiq.redis {|c|
            c.multi do
              c.del("failed")
              c.set("stat:failed", 0) if params["counter"]
            end
          }

          redirect "#{root_path}failures"
        end
      end
    def self.page_with_query(key, pageidx=1, page_size=25, query = '')
        current_page = pageidx.to_i < 1 ? 1 : pageidx.to_i
        pageidx = current_page - 1
        total_size = 0
        items = []
        starting = pageidx * page_size
        ending = starting + page_size - 1

        Sidekiq.redis do |conn|
          type = conn.type(key)
          case type
          when 'zset'
            total_size = conn.zcard(key)
            items = conn.zrange(key, starting, ending, :with_scores => true)
          when 'list'
            total_size = conn.llen(key)
            unless query.blank? 
                all_items = conn.lrange(key, 0, total_size)
                all_items.reject!{|item| !item.match query}
                total_size = all_items.size
                items = all_items[starting..ending]
            else
                items = conn.lrange(key, starting, ending)
            end
          when 'none'
            return [1, 0, []]
          else
            raise "can't page a #{type}"
          end
        end
        [current_page, total_size, items]
      end
    end
  end
end
