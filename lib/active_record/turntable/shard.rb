module ActiveRecord::Turntable
  class Shard
    module Connections; end
    def self.connection_classes
      Connections.constants.map { |name| Connections.const_get(name) }
    end

    attr_accessor :name, :slaves

    def initialize(name = defined?(Rails) ? Rails.env : "development", slaves = [])
      @name = name
      @slaves = slaves.map { |s| Shard.new(s) }
      ActiveRecord::Base.turntable_connections[name] = connection_pool
    end

    def connection_pool
      connection_klass.connection_pool
    end

    def connection
      if use_slave?
        current_slave_shard.connection
      else
        connection_pool.connection.tap do |conn|
          conn.turntable_shard_name ||= name
        end
      end
    end

    def support_slave?
      @slaves.size > 0
    end

    def use_slave?
      support_slave? && @use_slave
    end

    def current_slave_shard
      SlaveRegistry.slave_for(self) || SlaveRegistry.set_slave_for(self, any_slave)
    end

    def with_slave(slave = nil)
      slave ||= (current_slave || any_slave)
      old = current_slave
      set_current_slave(slave)
      yield
    ensure
      set_current_slave(old)
    end

    def with_master
      old = current_slave
      set_current_slave(nil)
      yield
    ensure
      set_current_slave(old)
    end

    private

      def connection_klass
        @connection_klass ||= create_connection_class
      end

      def create_connection_class
        klass = connection_class_instance
        klass.remove_connection
        klass.establish_connection ActiveRecord::Base.connection_pool.spec.config[:shards][name].with_indifferent_access
        klass
      end

      def connection_class_instance
        if Connections.const_defined?(name.classify)
          klass = Connections.const_get(name.classify)
        else
          klass = Class.new(ActiveRecord::Base)
          Connections.const_set(name.classify, klass)
          klass.abstract_class = true
        end
        klass
      end

      def set_current_slave_shard(slave)
        SlaveRegistry.set_slave_for(self, slave)
      end

      def any_slave
        slaves.sample
      end
  end
end
