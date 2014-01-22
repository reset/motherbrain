module MotherBrain
  module Gear
    class DynamicService < Gear::Base
      class << self

        # Parses a service, creates a new instance of DynamicService
        # and executes a Chef run to change the state of the service.
        #
        # @param service [String]
        #   a dotted string "component.service_name"
        # @param plugin [MB::Plugin]
        #   the plugin currently in use
        # @param environment [String]
        #   the environment to operate on
        # @param state [String]
        #   the state of the service to change to
        # @param options [Hash]
        # 
        # @return [MB::JobTicket]
        def change_service_state(service, plugin, environment, state, options = {})
          component, service_name = service.split('.')
          raise InvalidDynamicService.new(component, service_name) unless component && service_name

          dynamic_service = new(component, service_name)
          dynamic_service.async_state_change(plugin, environment, state, options)
        end
      end

      include MB::Mixin::Services
      include MB::Mixin::Locks
      include MB::Logging

      ACCEPTABLE_STATES = [
        "start",
        "stop",
        "restart"
      ].freeze

      # @return [String]
      attr_reader :component
      # @return [String]
      attr_reader :name

      def initialize(component, name)
        @name      = name
        @component = component
      end

      # Executes a bulk chef run on a group of nodes using the service recipe.
      # Default behavior is to set a node attribute on each individual node serially
      # and then execute the chef run.
      #
      # @param plugin [MB::Plugin]
      #   the plugin currently in use
      # @param environment [String]
      #   the environment to execute on
      # @param state [String]
      #   the state to change the service to
      # @param options [Hash]
      #
      # @return [MB::JobTicket]
      def async_state_change(plugin, environment, state, options = {})
        job = Job.new(:dynamic_service_state_change)

        log.warn { "Component's service state is being changed to #{state}, which is not one of #{ACCEPTABLE_STATES}" } unless ACCEPTABLE_STATES.include?(state)

        chef_synchronize(chef_environment: environment, force: options[:force]) do
          component_object = plugin.component(component)
          service_object = component_object.get_service(name)
          group = component_object.group(service_object.service_group)
          nodes = group.nodes(environment)

          job.report_running("preparing to change the #{name} service to #{state}")

          set_node_attributes(job, nodes, service_object.service_attribute, state)
          node_querier.bulk_chef_run(job, nodes, service_object.service_recipe)
        end

        job.report_success
        job.ticket
      rescue => ex
        job.report_failure(ex)
      ensure
        job.terminate if job && job.alive?
      end

      # Sets a default node attribute on the provided array
      # of nodes.
      #
      # @param job [MB::Job]
      #   the job to track status
      # @param nodes [Array<Ridley::NodeObject>]
      #   the nodes being operated on
      # @param attribute_key [String]
      #   a dotted path to an attribute key
      # @param state [String]
      #   the state to set the attribute to
      #
      # @return [type] [description]
      def set_node_attributes(job, nodes, attribute_key, state)
        nodes.concurrent_map do |node|
          node.reload
          
          job.set_status("Setting node attribute '#{attribute_key}' to #{state} on #{node.name}")
          node.set_chef_attribute(attribute_key, state)
          node.save
        end
      end
    end
  end
end
