
# -*- coding: utf-8 -*-
require 'rubygems'
require 'net/ssh'
require 'net/ssh/shell'
require 'net/scp'
require 'yaml'
require 'pp'

module  AlchemiaRoutine
  def config
    YAML::load_file('config.yml')
  end
end

#== アルケミアサーバーに入り、動画変換プログラムを実行し
#   コンテンツサーバーに転送する
class AlchemiaRoutine::Alchemia
  class << self # class methods
    include AlchemiaRoutine
    def run
      alchemia = config['account']['alchemia']
      Net::SSH.start(alchemia['host'], alchemia['user'], :password => alchemia['password']) do |ssh|

        # 処理対象のディレクトリを探し動画変換を実行
        dirs = Array.new
        ls = ssh.exec! 'ls -l'
        ls.each_line do |line|
          entry = line.split(' ').last
          if entry =~ /\d{6}/
            dirs << entry
          end
        end

        if dirs.max.nil?
          puts '処理対象のディレクトリがありませんでした'
          puts 'プログラムを終了します'
          return
        end

        command = "php MP4Box.php #{dirs.max}"
        pp command
        ssh.exec! command
        #ssh.shell do |sh|
        #  command = "php MP4Box.php #{dirs.max}"
        #  pp command
        #  php = sh.execute command
        #  sh.execute "exit"
        #end

        # sun.oki-max.netに動画を転送する
        okimax = config['account']['okimax']
        command =  sprintf("scp -r ~/tmp/* %s@%s:~/video/", okimax['user'], okimax['host'])
        ssh.open_channel do |channel|
          channel.request_pty do |ch, success|
            pp 'request pty'
          end

          channel.exec command do |ch, success|
            channel.on_data do |ch, data|
              puts data
              if data =~ /password/
                puts 'send password'
                channel.send_data okimax['password']
                channel.send_data "\n"
              end
            end

            channel.on_close do |ch|
              pp 'channel is closeing'
            end
          end
        end

        ssh.loop
      end
    end
  end
end

#== コンテンツサーバーにファイル転送し
#   登録プログラムを実行する
class AlchemiaRoutine::SunOkimax
  class << self
    include AlchemiaRoutine
    def upload
      pp 'upload alche.csv'
      okimax = config['account']['okimax']
      Net::SCP.start(okimax['host'], okimax['user'], :password => okimax['password']) do |scp|
        scp.upload! 'alche.csv', 'bin/'
      end
    end

    # 動画出力先を空にする
    def clean
      okimax = config['account']['okimax']
      pp okimax
      Net::SSH.start(okimax['host'], okimax['user'], :password => okimax['password']) do |ssh|
        puts 'rm -rf video/*'
        ssh.exec! 'rm -rf video/*'
        #ssh.shell('bash --norc --noprifile') do |sh|
        #  sh.execute 'cd video'
        #  sh.execute 'rm -rf *'
        #  sh.execute 'exit'
        #end
        ssh.loop
      end
    end

    # 動画登録
    def run
      okimax = config['account']['okimax']
      Net::SSH.start(okimax['host'], okimax['user'], :password => okimax['password']) do |ssh|
        ssh.shell do |sh|
          sh.execute 'cd bin'
          p = sh.execute 'php alche.php'
          puts "Exit Status:#{p.exit_status}"
          puts "Command Executed:#{p.command}"
          sh.execute 'exit'
        end
        ssh.loop
      end
    end
  end
end

#== Shift_JISのCSVファイルを読み込んでヘッダ以外をUTF8に変換して出力
class AlchemiaRoutine::Local
  class << self
    def convert
      rfp = File.open('alche.origin.csv', 'r', :external_encoding => Encoding::Shift_JIS, :internal_encoding => Encoding::UTF_8)
      wfp = File.open('alche.csv', 'w', :external_encoding => Encoding::UTF_8)
      rfp.gets
      while line = rfp.gets
        wfp.write(line)
      end
    end
  end
end

AlchemiaRoutine::Local::convert
AlchemiaRoutine::SunOkimax::clean
AlchemiaRoutine::SunOkimax::upload
AlchemiaRoutine::Alchemia::run
AlchemiaRoutine::SunOkimax::run

__END__
