require "log4r"
require 'rbconfig'
require "vagrant/util/subprocess"

module VagrantPlugins
  module Rackspace
    module Action
      # This middleware uses `rsync` to sync the folders over to the
      # remote instance.
      class SyncFolders
        def initialize(app, env)
          @app    = app
          @logger = Log4r::Logger.new("vagrant_rackspace::action::sync_folders")
          @host_os = RbConfig::CONFIG['host_os']
        end

        def call(env)
          @app.call(env)

          ssh_info = env[:machine].ssh_info

          env[:machine].config.vm.synced_folders.each do |id, data|
            hostpath  = File.expand_path(data[:hostpath], env[:root_path])
            guestpath = data[:guestpath]

            # Make sure there is a trailing slash on the host path to
            # avoid creating an additional directory with rsync
            hostpath = "#{hostpath}/" if hostpath !~ /\/$/
            
            # If on Windows, modify the path to work with cygwin rsync
            if @host_os =~ /mswin|mingw|cygwin/
              hostpath = hostpath.sub(/^([A-Za-z]):\//, "/cygdrive/#{$1.downcase}/")
            end

            env[:ui].info(I18n.t("vagrant_rackspace.rsync_folder",
                                :hostpath => hostpath,
                                :guestpath => guestpath))

            # Create the guest path
            env[:machine].communicate.sudo("mkdir -p '#{guestpath}'")
            env[:machine].communicate.sudo(
              "chown -R #{ssh_info[:username]} '#{guestpath}'")

            # Rsync over to the guest path using the SSH info. add
            # .hg/ to exclude list as that isn't covered in
            # --cvs-exclude
            command = [
              "rsync", "--verbose", "--archive", "-z",
              "--cvs-exclude", 
              "--exclude", ".hg/",
              "-e", "ssh -p #{ssh_info[:port]} -i '#{ssh_info[:private_key_path]}' -o StrictHostKeyChecking=no",
              hostpath,
              "#{ssh_info[:username]}@#{ssh_info[:host]}:#{guestpath}"]

            # during rsync, ignore files specified in .hgignore and
            # .gitignore traditional .gitignore or .hgignore files
            ignore_files = [".hgignore", ".gitignore"]
            ignore_files.each do |ignore_file|
              abs_ignore_file = env[:root_path].to_s + "/" + ignore_file
              if File.exist?(abs_ignore_file)
                command = command + ["--exclude-from", abs_ignore_file]
              end
            end

            r = Vagrant::Util::Subprocess.execute(*command)
            if r.exit_code != 0
              raise Errors::RsyncError,
                :guestpath => guestpath,
                :hostpath => hostpath,
                :stderr => r.stderr
            end
          end
        end
      end
    end
  end
end
