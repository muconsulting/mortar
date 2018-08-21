require "clamp"
require "base64"
require_relative "yaml_file"

Clamp.allow_options_after_parameters = true

module Mortar
  class Command < Clamp::Command
    banner "mortar - Kubernetes manifest shooter"

    option ['-v', '--version'], :flag, "print mortar version" do
      puts "mortar #{Mortar::VERSION}"
      exit 0
    end
    option ["-d", "--debug"], :flag, "debug"

    parameter "NAME", "deployment name"
    parameter "SRC", "source folder"

    LABEL = 'mortar.kontena.io/shot'
    CHECKSUM_ANNOTATION = 'mortar.kontena.io/shot-checksum'

    def execute
      signal_usage_error("#{src} is not a directory") unless File.exist?(src)
      stat = File.stat(src)
      signal_usage_error("#{src} is not a directory") unless stat.directory?

      resources = from_files(src)

      #K8s::Logging.verbose!
      K8s::Stack.new(
        name, resources,
        debug: debug?,
        label: LABEL, 
        checksum_annotation: CHECKSUM_ANNOTATION
      ).apply(client)
      puts "pushed #{name} successfully!"
    end

    # @param filename [String] file path
    # @return [Array<K8s::Resource>]
    def from_files(path)
      Dir.glob("#{path}/*.{yml,yaml}").sort.map { |file| self.from_file(file) }.flatten
    end

    # @param filename [String] file path
    # @return [K8s::Resource]
    def from_file(filename)
      K8s::Resource.new(YamlFile.new(filename).load)
    end

    # @return [K8s::Client]
    def client
      return @client if @client

      if ENV['KUBE_TOKEN'] && ENV['KUBE_CA'] && ENV['KUBE_SERVER']
        kubeconfig = K8s::Config.new(
          clusters: [
            {
              name: 'kubernetes',
              cluster: {
                server: ENV['KUBE_SERVER']
              }
            }
          ],
          users: [
            {
              name: 'mortar',
              user: {
                client_certificate_data: Base64.strict_decode64(ENV['KUBE_CA']),
                token: ENV['KUBE_TOKEN']
              }
            }
          ],
          contexts: [
            {
              name: 'mortar',
              context: {
                cluster: 'kubernetes',
                user: 'mortar'
              }
            }
          ],
          preferences: {},
          current_context: 'mortar'
        )
        @client = K8s::Client.new(K8s::Transport.config(kubeconfig))
      elsif ENV['KUBECONFIG']
        @client = K8s::Client.config(K8s::Config.load_file(ENV['KUBECONFIG']))
      else
        @client = K8s::Client.in_cluster_config
      end
    end
  end
end