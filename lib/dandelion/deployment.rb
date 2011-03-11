require 'dandelion/git'

module Dandelion
  module Deployment
    class RemoteRevisionError < StandardError; end
    class FastForwardError < StandardError; end
  
    class Deployment
      def initialize(repo, service, exclude = nil, revision = 'HEAD')
        @repo = repo
        @service = service
        @exclude = exclude || []
        @tree = Git::Tree.new(@repo, revision)
      end
    
      def local_revision
        @tree.revision
      end
    
      def remote_revision
        nil
      end
    
      def remote_uri
        @service.uri
      end
    
      def write_revision
        @service.write('.revision', local_revision)
      end
      
      def validate_state(remote = nil)
        if remote and @repo.git.native(:remote, {:raise => true}, 'show', remote) =~ /fast-forward/i
          raise FastForwardError
        end
      end
      
      def log
        Dandelion.logger
      end
    
      protected
    
      def exclude_file?(file)
        return @exclude.map { |e| file.start_with?(e) }.any?
      end
    end
  
    class DiffDeployment < Deployment
      def initialize(repo, service, exclude = nil, revision = 'HEAD')
        super(repo, service, exclude, revision)
        @diff = Git::Diff.new(@repo, read_remote_revision, revision)
      end
    
      def remote_revision
        @diff.from_revision
      end
    
      def deploy
        if !revisions_match? && any?
          deploy_changed
          deploy_deleted
        else
          log.info("Nothing to deploy")
        end
        unless revisions_match?
          write_revision
        end
      end
    
      def deploy_changed
        @diff.changed.each do |file|
          if exclude_file?(file)
            log.info("Skipping file: #{file}")
          else
            log.info("Uploading file: #{file}")
            @service.write(file, @tree.show(file))
          end
        end
      end
    
      def deploy_deleted
        @diff.deleted.each do |file|
          if exclude_file?(file)
            log.info("Skipping file: #{file}")
          else
            log.info("Deleting file: #{file}")
            @service.delete(file)
          end
        end
      end
    
      def any?
        @diff.changed.any? || @diff.deleted.any?
      end
    
      def revisions_match?
        remote_revision == local_revision
      end
    
      private
    
      def read_remote_revision
        begin
          @service.read('.revision').chomp
        rescue Service::MissingFileError
          raise RemoteRevisionError
        end
      end
    end
  
    class FullDeployment < Deployment
      def deploy
        @tree.files.each do |file|
          if exclude_file?(file)
            log.info("Skipping file: #{file}")
          else
            log.info("Uploading file: #{file}")
            @service.write(file, @tree.show(file))
          end
        end
        write_revision
      end
    end
  end
end