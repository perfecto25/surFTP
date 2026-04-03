require "./models/user"
require "./db/database"
require "./db/user_repo"
require "./system/crypto"
require "./server/config"
require "./server/log"
require "./server/libssh"
require "./server/virtual_fs"
require "./server/sftp_session"
require "./server/auth"
require "./server/audit_log"
require "./server/session_registry"
require "./server/ssh_server"
require "./server/manager"
require "./tui/components"
require "./tui/views/main_menu"
require "./tui/views/user_list"
require "./tui/views/user_form"
require "./tui/views/server_status"
require "./tui/app"
require "./client/encryption"
require "./client/config"
require "./client/connection"
require "./cli/commands"
require "./cli/parser"

module SurFTP
  {% begin %}
  VERSION = {{ `shards version "#{__DIR__}"`.chomp.stringify.downcase }}
  {% end %}
end

SurFTP::CLI::Parser.run(ARGV)
