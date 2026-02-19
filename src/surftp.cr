require "./models/user"
require "./db/database"
require "./db/user_repo"
require "./system/crypto"
require "./system/user_manager"
require "./server/config_generator"
require "./server/auth_handler"
require "./server/manager"
require "./tui/components"
require "./tui/views/main_menu"
require "./tui/views/user_list"
require "./tui/views/user_form"
require "./tui/views/server_status"
require "./tui/app"
require "./cli/commands"
require "./cli/parser"

module SurFTP
  {% begin %}
  VERSION = {{ `shards version "#{__DIR__}"`.chomp.stringify.downcase }}
  {% end %}
end

SurFTP::CLI::Parser.run(ARGV)
