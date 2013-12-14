module Timeline::Track::Now
  extend ActiveSupport::Concern

  module ClassMethods
    def track_now(name, user, object, options={})
      @actor = user
      @object = object
      @target = !options[:target].nil? ? send(options[:target].to_sym) : nil
      @fields_for = {}
      @extra_fields ||= nil
      @followers = @actor.followers
      add_activity activity(verb: name)
    end

    private
      def activity(options={})
        {
          verb: options[:verb],
          actor: options_for(@actor),
          object: options_for(@object),
          target: options_for(@target),
          created_at: Time.now
        }
      end

      def add_activity(activity_item)
        redis_add "global:activity", activity_item
        add_activity_to_user(activity_item[:actor][:id], activity_item)
        add_activity_by_user(activity_item[:actor][:id], activity_item)
        add_activity_to_followers(activity_item) if @followers.any?
      end

      def add_activity_by_user(user_id, activity_item)
        redis_add "user:id:#{user_id}:posts", activity_item
      end

      def add_activity_to_user(user_id, activity_item)
        redis_add "user:id:#{user_id}:activity", activity_item
      end

      def add_activity_to_followers(activity_item)
        @followers.each { |follower| add_activity_to_user(follower.id, activity_item) }
      end

      def extra_fields_for(object)
        return {} unless @fields_for.has_key?(object.class.to_s.downcase.to_sym)
        @fields_for[object.class.to_s.downcase.to_sym].inject({}) do |sum, method|
          sum[method.to_sym] = @object.send(method.to_sym)
          sum
        end
      end

      def options_for(target)
        if !target.nil?
          {
            id: target.id,
            klass: target.class.to_s,
            display_name: target.to_s
          }.merge(extra_fields_for(target))
        else
          nil
        end
      end

      def redis_add(list, activity_item)
        Timeline.redis.lpush list, Timeline.encode(activity_item)
        # Trim list so it doesn't get stupidly big. This will keep 300 elements
        Timeline.redis.ltrim list, 0, 299
      end
  end

end