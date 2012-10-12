module MotherBrain
  # @author Jamie Winsor <jamie@vialstudios.com>
  class Component
    include Mixin::SimpleAttributes
    include DynamicGears

    attr_reader :groups
    attr_reader :commands

    def initialize(environment, chef_conn, &block)
      @environment = environment
      @chef_conn = chef_conn
      @groups   = Set.new
      @commands = Set.new

      if block_given?
        dsl_eval(&block)
      end
    end

    # @return [Symbol]
    def id
      self.name.to_sym
    end

    # @param [#to_sym] name
    def group(name)
      self.groups.find { |group| group.name == name }
    end

    # @param [#to_sym] name
    def command(name)
      self.commands.find { |command| command.name == name }
    end

    # Run a command of the given name on the component.
    #
    # @param [String, Symbol] name
    def invoke(name)
      self.command(name).invoke
    end

    # Finds the nodes for the given environment for each {Group} and groups them
    # by Group#name into a Hash where the keys are Group#name and values are a Hash
    # representation of a node from Chef.
    #
    # @example
    #
    #   {
    #     "database_masters" => [
    #       {
    #         "name" => "db-master1",
    #         ...
    #       }
    #     ],
    #     "database_slaves" => [
    #       {
    #         "name" => "db-slave1",
    #         ...
    #       },
    #       {
    #         "name" => "db-slave2"
    #         ...
    #       }
    #     ]
    #   }
    #
    # @return [Hash]
    def nodes(environment)
      {}.tap do |nodes|
        self.groups.each do |group|
          nodes[group.name] = group.nodes(environment)
        end
      end
    end

    def add_group(group)
      self.groups.add(group)
    end

    private

      attr_reader :environment
      attr_reader :chef_conn

      def dsl_eval(&block)
        self.attributes = CleanRoom.new(self, environment, chef_conn, &block).attributes
        self
      end      

    # @author Jamie Winsor <jamie@vialstudios.com>
    # @api private
    class CleanRoom
      include Mixin::SimpleAttributes

      def initialize(component, environment, chef_conn, &block)
        @component = component
        @environment = environment
        @chef_conn = chef_conn

        instance_eval(&block)
      end

      # @param [String] value
      def name(value)
        set(:name, value, kind_of: String, required: true)
      end

      # @param [String] value
      def description(value)
        set(:description, value, kind_of: String, required: true)
      end

      def group(&block)
        component.add_group Group.new(environment, chef_conn, &block)
      end

      private

        attr_reader :component
        attr_reader :environment
        attr_reader :chef_conn
    end
  end
end
